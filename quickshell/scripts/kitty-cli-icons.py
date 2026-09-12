#!/usr/bin/env python3
"""Detects which known CLI tool is running in the foreground of each open
kitty window, for the Quickshell workspace pill's per-window icons.

kitty.conf sets `listen_on unix:/tmp/kitty-sichos-{kitty_pid}` (one socket
per kitty top-level window/process, remote control already enabled there),
and that {kitty_pid} is the same pid Hyprland reports for the window
(confirmed live via `hyprctl clients -j`) -- so the socket filename alone is
enough to key results by pid, with no separate window-address correlation
needed. `kitty @ ls` on each socket returns that window's own
foreground_processes[0].cmdline, which is authoritative for what's actually
running (unlike the window title, which for Claude Code reflects a status
glyph + task summary, not a fixed "claude" string).

Queries every socket concurrently (Workspaces.qml polls this every second,
and running `kitty @ ls` serially across several windows can add up to
longer than that, starving every other window's update whenever one socket
is briefly slow).

Emits JSON: { "<kitty pid>": "<icon key>", ... }. A pid maps to "" when its
query succeeded but nothing recognized is running (plain shell etc.) --
Workspaces.qml treats that as confirmed-idle and clears any icon. A pid is
omitted entirely only when the query itself failed (socket not ready yet,
timeout) -- Workspaces.qml then keeps whatever it last knew for that pid
instead of flickering the icon away for one bad tick.
"""
import glob
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# First path component of the foreground process's argv[0] -> icon key.
# "chatgpt" has no real CLI installed on this machine yet -- update this key
# once a specific tool/binary is chosen; until then it will just never match.
KNOWN_COMMANDS = {
    "claude": "claude",
    "agy": "agy",
    "chatgpt": "chatgpt",
    "nvim": "nvim",
}


def detect_command(sock_path):
    """Returns the icon key, "" for a confirmed-but-unrecognized foreground
    process, or None if the query itself failed."""
    try:
        out = subprocess.run(
            ["kitty", "@", "--to", "unix:" + sock_path, "ls"],
            capture_output=True, text=True, timeout=1,
        ).stdout
        data = json.loads(out)
    except Exception:
        return None

    for os_window in data:
        for tab in os_window.get("tabs", []):
            for win in tab.get("windows", []):
                procs = win.get("foreground_processes") or []
                if not procs:
                    continue
                cmdline = procs[0].get("cmdline") or []
                if not cmdline:
                    continue
                name = cmdline[0].rsplit("/", 1)[-1]
                return KNOWN_COMMANDS.get(name, "")
    return ""


def main():
    sock_paths = glob.glob("/tmp/kitty-sichos-*")
    with ThreadPoolExecutor(max_workers=max(1, len(sock_paths))) as pool:
        icon_keys = pool.map(detect_command, sock_paths)

    result = {}
    for sock_path, icon_key in zip(sock_paths, icon_keys):
        if icon_key is not None:
            pid = sock_path.rsplit("-", 1)[-1]
            result[pid] = icon_key
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
